/// The browser's event-stream link as a DOM-free JavaScript function, embedded in `/controls.js`.
/// A closed `EventSource` never reconnects by itself, so the link replaces it with backoff. The link
/// remembers the id of the last event it saw and opens the replacement from it, so the server can
/// replay what was missed; `onOpen` is told whether the connection resumes a stream, in which case
/// the page keeps what it shows and refreshes only when the server says it missed events.
enum LiveLink {
  static let source = #"""
  const isDeviceAddress = address => typeof address === 'string' && /^[0-9A-F]{2}(\.[0-9A-F]{2}){2}$/i.test(address);
  // What the page does with one frame of the stream. A frame of a kind it does not know, such as a notification,
  // changes nothing the page shows.
  const interpretFrame = data => {
    try {
      const update = JSON.parse(data);
      if (update?.version !== 1) return { action: 'ignore' };
      if (update.kind === 'modemUnavailable' && typeof update.message === 'string') return { action: 'hubAway', message: update.message };
      if (update.kind === 'gap') return { action: 'synchronize' };
      if (update.kind === 'reconnected') return { action: 'reconnected' };
      if (!isDeviceAddress(update.address)) return { action: 'ignore' };
      if (!['commandCompleted', 'identified', 'setButtonPressed'].includes(update.kind)) return { action: 'ignore' };
      return { action: 'refreshCard', address: update.address.toUpperCase() };
    } catch { return { action: 'ignore' }; }
  };
  const createLiveLink = ({ open, schedule, cancel, onState, onOpen, onClosed, onMessage }) => {
    const CLOSED = 2, firstDelay = 500, longestDelay = 30000;
    let source = null, timer = 0, delay = firstDelay, lastEventId = '';
    const clearTimer = () => { if (timer) cancel(timer); timer = 0; };
    const start = () => {
      if (source && source.readyState !== CLOSED) return;
      clearTimer();
      onState('connecting');
      const connection = open(lastEventId);
      source = connection;
      let opened = false;
      connection.onopen = () => {
        if (source !== connection) return;
        // The browser resumes a stream it opened before from its own last id.
        const resumed = lastEventId !== '' || opened;
        opened = true;
        delay = firstDelay;
        onState('connected');
        onOpen(resumed);
      };
      connection.onerror = () => {
        if (source !== connection) return;
        if (connection.readyState !== CLOSED) { onState('paused'); return; }
        onState('reconnecting');
        onClosed();
        clearTimer();
        timer = schedule(() => { timer = 0; start(); }, delay);
        delay = Math.min(delay * 2, longestDelay);
      };
      connection.onmessage = event => {
        if (source !== connection) return;
        if (typeof event.lastEventId === 'string' && event.lastEventId !== '') lastEventId = event.lastEventId;
        onMessage(event.data);
      };
    };
    const stop = () => {
      clearTimer();
      const connection = source;
      source = null;
      connection?.close();
    };
    return { start, stop };
  };
  """#
}
