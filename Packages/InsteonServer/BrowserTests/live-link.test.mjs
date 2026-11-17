// Scripted scenarios for the browser's event-stream link. The module is read from the Swift
// source that the server embeds in /controls.js, so the test runs exactly what browsers run.
// Nothing here waits on time: timers are recorded and fired by the test.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const swift = readFileSync(fileURLToPath(new URL('../Sources/InsteonHTTP/LiveLink.swift', import.meta.url)), 'utf8');
const source = swift.split('#"""\n')[1].split('\n  """#')[0];
const createLiveLink = new Function(source + '\nreturn createLiveLink;')();

const CONNECTING = 0, OPEN = 1, CLOSED = 2;

class ScriptedSource {
  constructor() { this.readyState = CONNECTING; this.closeCount = 0; }
  close() { this.readyState = CLOSED; this.closeCount++; }
  opens() { this.readyState = OPEN; this.onopen?.(); }
  fails(state) { this.readyState = state; this.onerror?.(); }
  says(data) { this.onmessage?.({ data }); }
}

const harness = () => {
  const sources = [], timers = new Map(), log = [];
  let nextTimer = 1;
  const link = createLiveLink({
    open: () => { const s = new ScriptedSource(); sources.push(s); return s; },
    schedule: (fn, ms) => { const id = nextTimer++; timers.set(id, { fn, ms }); return id; },
    cancel: id => timers.delete(id),
    onState: state => log.push(['state', state]),
    onOpen: () => log.push(['open']),
    onClosed: () => log.push(['closed']),
    onMessage: data => log.push(['message', data])
  });
  const pending = () => Array.from(timers.values());
  const fire = () => { const [id, timer] = Array.from(timers.entries())[0]; timers.delete(id); timer.fn(); };
  return { link, sources, log, pending, fire, states: () => log.filter(e => e[0] === 'state').map(e => e[1]) };
};

test('start opens one source and reports connecting', () => {
  const h = harness();
  h.link.start();
  h.link.start();
  assert.equal(h.sources.length, 1);
  assert.deepEqual(h.states(), ['connecting']);
});

test('opening reports connected and asks the page to refresh', () => {
  const h = harness();
  h.link.start();
  h.sources[0].opens();
  assert.deepEqual(h.states(), ['connecting', 'connected']);
  assert.equal(h.log.filter(e => e[0] === 'open').length, 1);
});

test('a source the browser closed after a 502 is replaced, then the page refreshes', () => {
  const h = harness();
  h.link.start();
  h.sources[0].opens();
  h.sources[0].fails(CLOSED);
  assert.equal(h.states().at(-1), 'reconnecting');
  assert.deepEqual(h.pending().map(t => t.ms), [500]);
  h.fire();
  assert.equal(h.sources.length, 2);
  assert.equal(h.states().at(-1), 'connecting');
  h.sources[1].opens();
  assert.equal(h.states().at(-1), 'connected');
  assert.equal(h.log.filter(e => e[0] === 'open').length, 2);
});

test('backoff doubles to a cap and a successful open resets it', () => {
  const h = harness();
  h.link.start();
  const delays = [];
  for (let i = 0; i < 9; i++) {
    h.sources.at(-1).fails(CLOSED);
    delays.push(h.pending()[0].ms);
    h.fire();
  }
  assert.deepEqual(delays, [500, 1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000]);
  h.sources.at(-1).opens();
  h.sources.at(-1).fails(CLOSED);
  assert.equal(h.pending()[0].ms, 500);
});

test('each closure tells the page so it can check authentication', () => {
  const h = harness();
  h.link.start();
  h.sources[0].fails(CLOSED);
  h.fire();
  h.sources[1].fails(CLOSED);
  assert.equal(h.log.filter(e => e[0] === 'closed').length, 2);
});

test('while the browser retries by itself the link only reports paused', () => {
  const h = harness();
  h.link.start();
  h.sources[0].opens();
  h.sources[0].fails(CONNECTING);
  assert.equal(h.states().at(-1), 'paused');
  assert.equal(h.pending().length, 0);
  assert.equal(h.sources.length, 1);
  h.sources[0].opens();
  assert.equal(h.states().at(-1), 'connected');
});

test('start on a closed source reconnects at once and drops the pending timer', () => {
  const h = harness();
  h.link.start();
  h.sources[0].fails(CLOSED);
  h.link.start();
  assert.equal(h.sources.length, 2);
  assert.equal(h.pending().length, 0);
});

test('start leaves a live source alone', () => {
  const h = harness();
  h.link.start();
  h.sources[0].opens();
  h.link.start();
  assert.equal(h.sources.length, 1);
});

test('stop closes the source, cancels the timer and ignores late events', () => {
  const h = harness();
  h.link.start();
  h.sources[0].fails(CLOSED);
  h.link.stop();
  assert.equal(h.pending().length, 0);
  h.link.start();
  h.link.stop();
  assert.equal(h.sources[1].closeCount, 1);
  const before = h.log.length;
  h.sources[1].opens();
  h.sources[1].says('{}');
  h.sources[1].fails(CLOSED);
  assert.equal(h.log.length, before);
  assert.equal(h.pending().length, 0);
});

test('events from a replaced source are ignored', () => {
  const h = harness();
  h.link.start();
  h.sources[0].fails(CLOSED);
  h.fire();
  const before = h.log.length;
  h.sources[0].opens();
  h.sources[0].says('stale');
  assert.equal(h.log.length, before);
});

test('messages reach the page', () => {
  const h = harness();
  h.link.start();
  h.sources[0].opens();
  h.sources[0].says('{"version":1}');
  assert.deepEqual(h.log.at(-1), ['message', '{"version":1}']);
});
