/// The browser's event-stream link as a DOM-free JavaScript function, embedded in `/controls.js`.
/// A closed `EventSource` never reconnects by itself, so the link replaces it with backoff.
enum LiveLink {
  static let source = #"""
  const createLiveLink = ({ open, schedule, cancel, onState, onOpen, onClosed, onMessage }) => {
    const CLOSED = 2, firstDelay = 500, longestDelay = 30000;
    let source = null, timer = 0, delay = firstDelay;
    const clearTimer = () => { if (timer) cancel(timer); timer = 0; };
    const start = () => {
      if (source && source.readyState !== CLOSED) return;
      clearTimer();
      onState('connecting');
      const connection = open();
      source = connection;
      connection.onopen = () => {
        if (source !== connection) return;
        delay = firstDelay;
        onState('connected');
        onOpen();
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
        if (source === connection) onMessage(event.data);
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
