import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';
import { functionNames, resultCodes } from '../supabase/functions/_shared/observability.ts';

// Accept only our small schema. Never echo rejected log lines or trace IDs.
export async function summarizeLogs(lines) {
  const groups = new Map();
  let accepted = 0, ignored = 0;
  for await (const line of lines) {
    let event;
    try { if (line.length > 2048) throw Error(); event = JSON.parse(line); } catch { ignored++; continue; }
    if (event?.event !== 'imagineos.request' || event.schema !== 1 ||
        !functionNames.includes(event.function) || !resultCodes.has(event.code) ||
        !Number.isInteger(event.status) || event.status < 100 || event.status > 599 ||
        !Number.isInteger(event.duration_ms) || event.duration_ms < 0 || event.duration_ms > 600000) {
      ignored++; continue;
    }
    // Bounded cardinality: four functions × finite codes × HTTP statuses.
    const key = `${event.function}:${event.status}:${event.code}`;
    const value = groups.get(key) ?? { function: event.function, status: event.status,
      code: event.code, count: 0, total_ms: 0, max_ms: 0 };
    value.count++; value.total_ms += event.duration_ms;
    value.max_ms = Math.max(value.max_ms, event.duration_ms);
    groups.set(key, value); accepted++;
  }
  return { schema: 1, accepted, ignored, groups: [...groups.values()].map(({total_ms,...group}) =>
      ({...group, mean_ms: Math.round(total_ms / group.count)}))
    .sort((a,b) => a.function.localeCompare(b.function) || a.status-b.status || a.code.localeCompare(b.code)) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const lines = createInterface({input: process.stdin, crlfDelay: Infinity});
  console.log(JSON.stringify(await summarizeLogs(lines), null, 2));
}
